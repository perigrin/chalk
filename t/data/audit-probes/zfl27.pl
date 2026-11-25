my $s="ab"; sub f { "@_" } print f($s, $s.="c"), "\n";
