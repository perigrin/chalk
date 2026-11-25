printf("%s %s %s\n", "a", "b", "c"); printf("%-3s|%3s|%03d|%.2f|%5.1f|%x|%e\n", "a", "b", 7, 3.14159, 2.5, 255, 12345.678); printf("%s\n", join ",", map { sprintf "%3d%%", $_ * 10 } 1..3);
