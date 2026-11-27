my $str = ""; my @st = ([0,"r"]); while (my $f = shift @st) { my ($d,$n) = @$f; $str .= $n; push @st, [$d+1,"${n}a"], [$d+1,"${n}b"] if $d < 1 } print "$str\n";
