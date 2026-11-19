our $s = ""; sub ap { $s .= $_[0] } $s .= "-"; ap("a"); $s .= "-"; ap("b"); print "$s\n";
