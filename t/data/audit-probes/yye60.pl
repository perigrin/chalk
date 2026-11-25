our $g="ab"; sub f { "@_" } print f($g, $g =~ tr/a/z/), "\n";
