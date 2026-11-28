our $s = "abc"; sub ed { $s =~ tr/b/z/; 1 } my @l = ($s, ed(), $s); print "@l\n";
