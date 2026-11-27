our ($g,$h) = (1,2); { local ($g,$h); print defined $g ? "d" : "u" } print "$g$h\n";
