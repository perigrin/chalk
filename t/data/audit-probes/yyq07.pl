print $^O eq "linux" ? "linux" : "other", $] >= 5.042 ? "new" : "old", "\n";
