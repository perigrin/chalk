sub c { wantarray ? "L" : "S" } for (c()) { print } if (c() eq "S") { print "s" } print c() ? "t" : "f", !c() ? "t" : "f", "\n";
