sub f { $_[0] .= "a" } my $s = ""; my $i = 0; while ($i++ < 3) { my $x; f($x); f($x) if $i > 1; $s .= "$x," } print "$s\n";
