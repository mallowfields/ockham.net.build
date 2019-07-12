using System;
using System.Collections.Generic;
using System.Text;

namespace $safeprojectname$
{
    public class SimpleClass
    {
        public static List<string> Repeat(string input, int count)
        {
            var result = new List<string>();
            for (int i = 0; i < count; i++) result.Add(input);
            return result;
        }
    }
}
