our $g="a"; sub f { "@_" } print f($g, $g .= "b"), "\n";
