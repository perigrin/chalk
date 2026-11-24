our $n=3; sub r { return $_[0] if $n==0; $n--; r($_[0]) } print r($n),"\n";
