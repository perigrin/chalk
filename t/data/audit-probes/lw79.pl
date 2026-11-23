my @a=(1,2); my $s=""; sub show { $s .= "@a;" } for (@a) { $_ .= "x"; show() } print "$s\n";
