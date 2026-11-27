print join("|", split(/(-)|(\+)/, "a-b+c")) =~ s/\|\|/|u|/gr, " ", join("|", split /x/, "axbxc", -1), " ", join("|", split(//, "ab", 5)), " ", join("|", split(/^/, "a\nb\n")) =~ s/\n/N/gr, "\n";
