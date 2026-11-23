my @a=(1,2); my $s=""; sub show { $s .= "@a;" } for my $e (@a) { $e .= "x"; show() } print "$s\n";
