our @g = (1); { local $g[3] = 9; print scalar(@g) } print scalar(@g), "\n";
