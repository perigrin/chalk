my %h = (a=>1); my @l = ($h{a}, delete $h{a}, exists $h{a} ? 1 : 0); print "@l\n";
