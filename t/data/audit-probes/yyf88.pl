my ($x,$y,$c)=(0,0,1); for (1..3) { $c && ($x = $x + 5); $c = !$c; $c or $y++ } print "$x $y\n";
