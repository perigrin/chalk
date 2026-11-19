our $s = "q"; sub ap { $s .= $_[0] } ap("a"); $s .= "-$s"; ap("b"); print "$s\n";
