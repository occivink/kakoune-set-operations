provide-module set-operations %§

define-command set-operation -hidden -params .. -docstring '
TODO
' %{
    # TODO re-update the mark register, so that the timestamp matches
    eval %sh{
        operation_set=0
        operation=''
        register_name='^'

        while [ "$#" -ge 1 ]; do
            if [ "$1" = '-register' ]; then
                shift
                if [ "$#" -eq 0 ]; then
                    printf 'fail TODO'
                    exit
                fi
                register_name="$1"
            else
                if [ "$operation_set" != 0 ]; then
                    printf 'fail TODO'
                    exit
                fi
                case "$1" in
                    'union') ;;
                    'intersection') ;;
                    'difference') ;;
                    *)
                        printf 'fail TODO'
                        exit
                        ;;
                esac
                operation="$1"
                operation_set=1
            fi
            shift
        done
        if [ "$operation_set" = 0 ]; then
            printf 'fail TODO'
            exit
        fi

        perl - "$operation" "$register_name" <<'EOF'
use strict;
use warnings;

my $operation = shift;
$operation = uc($operation);
my $register_name = shift;

my $command_fifo_name = $ENV{"kak_command_fifo"};
my $response_fifo_name = $ENV{"kak_response_fifo"};

sub parse_shell_quoted {
    my $str = shift;
    my @res;
    my $elem = "";
    while (1) {
        if ($str !~ m/\G'([\S\s]*?)'/gc) {
            exit(1);
        }
        $elem .= $1;
        if ($str =~ m/\G *$/gc) {
            push(@res, $elem);
            $elem = "";
            last;
        } elsif ($str =~ m/\G\\'/gc) {
            $elem .= "'";
        } elsif ($str =~ m/\G */gc) {
            push(@res, $elem);
            $elem = "";
        } else {
            exit(1);
        }
    }
    return @res;
}

sub read_array {
    my $what = shift;

    open (my $command_fifo, '>', $command_fifo_name);
    print $command_fifo "echo -quoting shell -to-file $response_fifo_name -- $what";
    close($command_fifo);

    # slurp the response_fifo content
    open (my $response_fifo, '<', $response_fifo_name);
    my $response_quoted = do { local $/; <$response_fifo> };
    close($response_fifo);
    return parse_shell_quoted($response_quoted);
}

sub compare_coords {
    my $first = shift;
    my $second = shift;
    if ("$first $second" !~ m/(\d+)\.(\d+) (\d+)\.(\d+)/) {
        exit(1);
    }
    if ($1 < $3) {
        return -1;
    } elsif ($1 > $3) {
        return 1;
    } elsif ($2 < $4) {
        return -1;
    } elsif ($2 > $4) {
        return 1;
    }
    return 0;
}

sub get_selection_coords {
    my $input = shift;
    if ($input !~ m/^(.*?),(.*?)$/) {
        exit(1);
    }
    my $res = compare_coords($1, $2);
    if ($res == 1) {
        return ($2, $1);
    } else {
        return ($1, $2);
    }
}

use constant FIRST_ENTIRELY_BEFORE_SECOND => 1;
use constant FIRST_END_OVERLAPS_SECOND_BEGIN => 2;
use constant FIRST_ENTIRELY_AFTER_SECOND => 3;
use constant FIRST_BEGIN_OVERLAPS_SECOND_END => 4;
use constant FIRST_CONTAINS_SECOND => 5;
use constant FIRST_CONTAINED_BY_SECOND => 6;
use constant FIRST_EQUALS_SECOND => 7;

sub compare_selection {
    my $beg1 = shift;
    my $end1 = shift;
    my $beg2 = shift;
    my $end2 = shift;
    my $res1 = compare_coords($end1, $beg2);
    if ($res1 == -1) {
        return FIRST_ENTIRELY_BEFORE_SECOND;
    }

    my $res2 = compare_coords($beg1, $end2);
    if ($res2 == 1) {
        return FIRST_ENTIRELY_AFTER_SECOND;
    }

    my $res3 = compare_coords($beg1, $beg2);
    my $res4 = compare_coords($end1, $end2);

    if ($res3 == 0 && $res4 == 0) {
        return FIRST_EQUALS_SECOND;
    } elsif ($res3 <= 0 && $res4 >= 0) {
        return FIRST_CONTAINS_SECOND;
    } elsif ($res3 >= 0 && $res4 <= 0) {
        return FIRST_CONTAINED_BY_SECOND;
    }

    if ($res1 >= 0) {
        return FIRST_END_OVERLAPS_SECOND_BEGIN;
    } elsif ($res2 <= 0) {
        return FIRST_BEGIN_OVERLAPS_SECOND_END;
    }

    exit(1);
    return 0;
}

my @current_selections_descs = read_array("%val{selections_desc}");
my @register_selections_descs = read_array("%reg{$register_name}");
# TODO check that the buffer/timestamp is correct
shift(@register_selections_descs);

my $num_current_selections = scalar(@current_selections_descs);
my $num_register_selections = scalar(@register_selections_descs);
if ($num_current_selections == 0 || $num_register_selections == 0) {
    exit(1);
}

# in $kak_selections_desc, the main selection is at the front
# we just put it back in its place, so that it matches $kak_selections
# TODO

my @new_selections;

sub print_debug {
    my $what = shift;
    print("echo -debug '$what'\n");
}

if ($operation eq 'INTERSECTION') {
    my $i = 0;
    my $j = 0;
    while (1) {
        my $current_sel = $current_selections_descs[$i];
        my $secondary_sel = $register_selections_descs[$j];

        my ($beg1, $end1) = get_selection_coords($current_sel);
        my ($beg2, $end2) = get_selection_coords($secondary_sel);

        my $overlap = compare_selection($beg1, $end1, $beg2, $end2);

        if ($overlap == FIRST_ENTIRELY_BEFORE_SECOND) {
            # noop
        } elsif ($overlap == FIRST_ENTIRELY_AFTER_SECOND) {
            # noop
        } elsif ($overlap == FIRST_CONTAINS_SECOND) {
            push(@new_selections, $secondary_sel);
        } elsif ($overlap == FIRST_CONTAINED_BY_SECOND) {
            push(@new_selections, $current_sel);
        } elsif ($overlap == FIRST_EQUALS_SECOND) {
            push(@new_selections, $current_sel);
        } elsif ($overlap == FIRST_END_OVERLAPS_SECOND_BEGIN) {
            push(@new_selections, "$beg2,$end1");
        } elsif ($overlap == FIRST_BEGIN_OVERLAPS_SECOND_END) {
            push(@new_selections, "$beg1,$end2");
        }

        my $last_cur = ($i == ($num_current_selections - 1));
        my $last_reg = ($j == ($num_register_selections - 1));
        if ($last_cur && $last_reg) {
            last;
        } elsif ($last_cur) {
            $j++;
        } elsif ($last_reg) {
            $i++;
        } elsif (compare_coords($end1, $end2) >= 0) {
            $j++;
        } else {
            $i++;
        }
    }
} elsif ($operation eq 'UNION') {
    my $cur_beg;
    my $cur_end;
    my $has_cur = 0;
    while (1) {
        my $current_sel = $current_selections_descs[$i];
        my $secondary_sel = $register_selections_descs[$j];

        my ($beg1, $end1) = get_selection_coords($current_sel);
        my ($beg2, $end2) = get_selection_coords($secondary_sel);

        my $overlap = compare_selection($beg1, $end1, $beg2, $end2);
        
        if ($overlap == FIRST_ENTIRELY_BEFORE_SECOND) {
            if ($has_cur) {
                push(@new_selections, "$cur_beg,$end1");
                $has_cur = 0;
            } else {
                push(@new_selections, "$beg1,$end1");
            }
        } elsif ($overlap == FIRST_ENTIRELY_AFTER_SECOND) {
            if ($has_cur) {
                push(@new_selections, "$cur_beg,$end2");
                $has_cur = 0;
            } else {
                push(@new_selections, "$beg2,$end2");
            }
        } elsif ($overlap == FIRST_CONTAINS_SECOND) {
            if (!$has_cur) {
                $cur_beg = $beg1;
                $has_cur = 1;
            }
            $cur_end = $end1;
        } elsif ($overlap == FIRST_CONTAINED_BY_SECOND) {
            if (!$has_cur) {
                $cur_beg = $beg2;
                $has_cur = 1;
            }
            $cur_end = $end2;
        } elsif ($overlap == FIRST_EQUALS_SECOND) {
            if (!$has_cur) {
                $cur_beg = $beg1;
                $has_cur = 1;
            }
            $cur_end = $end1;
        } elsif ($overlap == FIRST_END_OVERLAPS_SECOND_BEGIN) {
            if (!$has_cur) {
                $cur_beg = $beg1;
                $has_cur = 1;
            }
            $cur_end = $end2;
        } elsif ($overlap == FIRST_BEGIN_OVERLAPS_SECOND_END) {
            if (!$has_cur) {
                $cur_beg = $beg2;
                $has_cur = 1;
            }
            $cur_end = $end1;
        }

        if (compare_coords($end1, $end2) >= 0) {
            $i++;
        } else {
            $j++;
        }
    }
} elsif ($operation eq 'DIFFERENCE') {
    my $i = 0;
    my $j = 0;
    while (1) {
        my $cur = $current_selections_descs[$i];
        my ($cur_beg, $cur_end) = get_selection_coords($cur);
        while (1) {
            my $second = $register_selections_descs[$j];
            my ($second_beg, $second_end) = get_selection_coords($second);
            
            my $overlap = compare_selection($cur_beg, $cur_end, $second_beg, $second_end);
            if ($overlap == FIRST_ENTIRELY_BEFORE_SECOND) {
                push(@new_selections, "$cur_beg,$cur_end");
                last;
            } elsif ($overlap == FIRST_EQUALS_SECOND) {
                last;
            } elsif ($overlap == FIRST_CONTAINS_SECOND) {
                if (compare_coords($second_beg, $cur_beg) == 1) {
                    push(, "$cur_beg,$second.beg-1")
                }
                if (compare_coords($cur_end, $second_end) == 1) {
                    cur_beg = second_end + 1;
                } else {
                    $j++;
                    last;
                }
            } elsif ($overlap == FIRST_END_OVERLAPS_SECOND_BEGIN) {
                if (compare_coords($second_beg, cur_beg) == 1) {
                    push(@, "$cur_beg,$second_beg" -1);
                }
                last;
            } elsif ($overlap == FIRST_ENTIRELY_AFTER_SECOND) {
                # empty
            } elsif ($overlap == FIRST_CONTAINED_BY_SECOND) {
                last;
            } elsif ($overlap == FIRST_BEGIN_OVERLAPS_SECOND_END) {
                $cur_beg = $second_end + 1;
            }
            $j++;
        }
        $i++;
    }
}

if (scalar(@new_selections) == 0) {
    print("fail 'No selections remaining'");
} else {
    print("select");
    for my $desc (@new_selections) {
        print(" '$desc'");
    }
    print(" ;");
}
exit(0);
EOF
        res=$?
        if [ $res != 0 ]; then
            printf "fail 'TODO $res'"
        fi
    }
}

#
#Int:
#            []      [ ]
#
#Union:
#[   ][         ]  [     ]
#
#difference
#[   ]         []
#
#leftdifff
#     [     ]      []   []
#
#i = 0
#j = 0
#[   ]       [  ]    [ ]
#     [       ]    [     ]
##intersection
#while (true) {
#    main-sel = sels1[i]
#    secondary-sel = sels2[j]
#
#    overlap = compute-overlap-type(first, second)
#
#    switch(overlap)
#        first_before:
#        second_before:
#            // nothing
#        first_contains:
#            push(second)
#        second_contains:
#            push(first)
#        first_end_overlaps_second_beg:
#            push({second.beg, first.end})
#        second_end_overlaps_first_beg:
#            push({first.beg, second.end})
#
#    if (j == max && i == max)
#        break
#    else if (i == max)
#        ++i
#    else if (j == max)
#        ++j
#    else if (first.end >= second.end)
#        ++j
#    else
#        ++i
#}
#
##union
#cur = None
#[][] [      ]     [          ]
#   [  ]  [  ]   [ ]         [    ]
#while (true) {
#    main-sel = sels1[i]
#    secondary-sel = sels2[j]
#
#    overlap = compute-overlap-type(main-sel, secondary-sel)
#
#    if (overlap == left-overlap|right-overlap)
#        if cur
#            cur.end = second.end
#        else
#            cur = {first.beg, second.end}
#    if (overlap = contained1|contained2)
#        if cur
#            cur.end = containing.end
#        else
#            cur = containig
#    if (entirely-before|entirely-before)
#        if cur
#            cur.end = before_one.end
#        else
#            cur = before_one
#        push(cur)
#        cur = None
#
#    if (secondary.end >= main.end)
#        ++i
#    else
#        ++j
#
#}
#
#while True:
#    first = sel[i]
#    cur = first
#    while True:
#        second = sel[j]
#        overlap = compute_overlap(cur, second)
#        switch(overlap)
#            first_before:
#                push(cur)
#                break
#            first_contains:
#                if second.beg > cur.beg:
#                    push(cur.beg, second.beg - 1)
#                if cur.end > second.end
#                    cur.beg = second.end+1
#                else
#                    ++j
#                    break
#            first_end_overlaps_second_beg:
#                if second.beg > cur.beg:
#                    push(cur.beg, second.beg - 1)
#                break
#            second_before:
#                // empty
#            second_contains
#                break
#            second_end_overlaps_first_beg:
#                cur.beg = second.end
#        ++j
#    ++i
#}
#
#rightdiff = leftdiff(second,main)

§
