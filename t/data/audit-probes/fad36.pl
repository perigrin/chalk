our $d=0; sub r { my $n=shift; local $d=$d+1; return $n ? r($n-1) : $d } print r(3), $d, "\n";
