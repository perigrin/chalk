our $g=1; sub f { $g=5; 1 } sub r { return ($g, f(), $g) } my @r=r(); print "@r\n";
