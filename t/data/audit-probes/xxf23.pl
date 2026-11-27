our ($g,$h) = (1,2); { local ($g,$h) = ($h,$g); print "$g$h" } print "$g$h\n";
