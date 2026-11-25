my $x = 1; my $r = \$x; my $c = $$r; $c++; my @a = ($x) x 2; $a[0]++; my %h = (k => $x); $h{k}++; print "$x\n";
