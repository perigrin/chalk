our $g=0; sub r { my $d = shift; local $g = $g + 1; return $d ? r($d-1) : $g } print r(3), $g, "\n";
