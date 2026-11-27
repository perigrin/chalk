our @g = (1,2,3); { local $#g = 0; } print scalar(@g), "\n" if 0; print "ok\n";
