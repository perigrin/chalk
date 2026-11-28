my $n = 1; my $c = sub { $n = $_[0] }; my $s = "$n"; $c->(7); $s .= $n; print "$s\n";
