sub c { wantarray ? "L" : "S" } my @x = (c())[0]; my $x = (c())[0]; print "@x$x", c() . "", "@{[ c() ]}\n";
