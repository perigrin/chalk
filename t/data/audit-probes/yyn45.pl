open(my $fh, "<", \ "a\nb\n") or die; my $s = ""; while (my $l = <$fh>) { chomp $l; $s .= $l; last if $l eq "a" } my $next = <$fh>; print $s, $next, eof($fh) ? "eof" : "more", "\n";
