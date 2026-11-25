open(my $fh, "<", \ "abcdef") or die; read($fh, my $b1, 2); read($fh, my $b2, 10); my $c = getc($fh); print "$b1|$b2|", defined $c ? "d" : "u", eof($fh) ? "eof" : "more", "\n";
