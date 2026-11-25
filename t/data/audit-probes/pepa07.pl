our $g="ab"; sub f { $g =~ tr/a/z/; $_[0] } print f($g), "\n";
