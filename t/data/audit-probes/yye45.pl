our $g=1; sub f { "@_" } my @r = (f($g, $g++), $g); print "@r\n";
