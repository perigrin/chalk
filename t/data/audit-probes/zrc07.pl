my $d=0; sub r { $d++; r($_[0]-1) if $_[0]; $d } print r(3), "\n";
