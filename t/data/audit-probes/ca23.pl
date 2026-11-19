my $d = 0; sub r { my $n = shift; $d++; return $n ? r($n - 1) : 0 } r(3); print "$d\n";
