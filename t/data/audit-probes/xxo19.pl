our ($p,%q) = (1,k=>2); { local ($p,%q) = (7,j=>8); print $p, join(",", %q) } print $p, join(",", %q), "\n";
