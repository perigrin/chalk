our $s = ""; sub ap { $s .= $_[0] } for my $c ("a".."c") { $s .= "-"; ap($c) } print "$s\n";
