my $s = ""; my $i = 0; { $s .= "a"; last if $i++; $s .= "b"; redo } print "$s\n";
