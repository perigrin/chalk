our $g=1; sub f { "@_" } print f(\$g == \$g ? $g : 0, $g++), "\n";
