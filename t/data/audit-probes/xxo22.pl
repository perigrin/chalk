our @g = (1,2,3); { delete local $g[2]; print scalar(@g) } print scalar(@g), "\n";
