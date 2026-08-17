# AnalyzeHexStrings.java — Ghidra headless post-script: locate diagnostic
# strings in the merged ADSP firmware and list xrefs so we can find the
# glink intent machinery.
#@category ADSP.RE
#@menupath Tools.ADSP.FindIntentStrings

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;
import java.util.*;

public class AnalyzeHexStrings extends GhidraScript {

	@Override
	public void run() throws Exception {
		String[] needles = {
			"Dropping intent req",
			"Could not notify RX Done",
			"Could not queue RX intent",
			"intent request timed",
			"glink_core_intent.c",
			"select",
			"slimbus_qmi",
			"IPCRTR",
		};
		Memory mem = currentProgram.getMemory();
		ReferenceManager refs = currentProgram.getReferenceManager();

		for (String needle : needles) {
			println("=== searching: " + needle + " ===");
			AddressIterator it = mem.findAllBytes(
				needle.getBytes("UTF-8"), new AddressSet(), true, monitor);
			int found = 0;
			while (it.hasNext() && found < 40) {
				Address a = it.next();
				found++;
				println("  string @ " + a);
				ReferenceIterator ri = refs.getReferencesTo(a);
				int rc = 0;
				while (ri.hasNext() && rc < 6) {
					Reference r = ri.next();
					println("    xref from " + r.getFromAddress());
					rc++;
				}
			}
			println("  total found: " + found);
		}
	}
}
