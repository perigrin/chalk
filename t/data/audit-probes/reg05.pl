our $g=1; sub f { $g++ } my @l = ($g+0, f(), $g+0); print "@l\n";
