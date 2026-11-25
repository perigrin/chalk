my $x="ab"; my $n = $x . ($x =~ tr/a/z/r) . $x; print "$n\n";
