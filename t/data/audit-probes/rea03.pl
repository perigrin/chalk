our $g=1; sub f { $g++ } my $x = $g + f() + $g; print "$x $g\n";
