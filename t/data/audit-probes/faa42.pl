my $x=1; sub g { $x++ } my $s = $x . g() . $x; print "$s\n";
