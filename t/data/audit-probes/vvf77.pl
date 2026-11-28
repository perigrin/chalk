my $x = 1; my %h = (a => $x, b => $x++, c => $x); print "$h{a}$h{b}$h{c}\n";
