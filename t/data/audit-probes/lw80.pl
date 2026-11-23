my @a=(1,2); my $s=""; sub show { $s .= join(",", @a) . ";" } for my $e (@a) { $e .= "x"; show(); last if $e eq "2x" } print "$s @a\n";
