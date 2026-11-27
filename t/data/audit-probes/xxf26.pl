our @g = (1,2); sub rd { "@g" } { local @g = (3); push @g, 4; print rd() } print rd(), "\n";
