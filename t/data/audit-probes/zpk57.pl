our $d=0; sub r { local $d=$d+1; $_[0] ? r($_[0]-1) : $d } print r(3), $d, "\n";
