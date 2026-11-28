my $s = ""; my $i = 0; { $s .= $i++; redo if $i < 3; } print "$s\n";
