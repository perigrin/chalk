my $cwd0 = do { require Cwd; Cwd::getcwd() }; chdir "/tmp"; my $cwd1 = Cwd::getcwd(); print $cwd0 ne $cwd1 ? "moved\n" : "same\n";
