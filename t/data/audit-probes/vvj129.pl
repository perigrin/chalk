my %h = (a=>1); my $t = 0; for (1..2) { while (my ($k, $v) = each %h) { $t += $v } } print "$t\n";
