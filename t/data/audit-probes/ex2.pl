eval { die [1,2] }; print ref($@) ? "ref" : "str", "\n";
