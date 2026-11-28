our $s = "abc"; sub ed { $s .= "d"; 1 } my @l = ($s, ed(), $s); print "@l\n";
