our $g=1; sub f { "$g @_" } print f($g, $g++), "\n";
