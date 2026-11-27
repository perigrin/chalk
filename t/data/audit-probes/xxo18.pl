our ($p,@q) = (1,2,3); { local ($p,@q) = (7,8); print "$p@q" } print "$p@q\n";
