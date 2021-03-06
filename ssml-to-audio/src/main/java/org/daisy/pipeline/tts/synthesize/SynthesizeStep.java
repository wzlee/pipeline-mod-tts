package org.daisy.pipeline.tts.synthesize;

import java.util.Collections;
import java.util.LinkedList;
import java.util.List;

import net.sf.saxon.s9api.Axis;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.SaxonApiException;
import net.sf.saxon.s9api.XdmNode;
import net.sf.saxon.s9api.XdmSequenceIterator;

import org.daisy.pipeline.audio.AudioEncoder;
import org.daisy.pipeline.tts.TTSRegistry;

import com.xmlcalabash.core.XProcRuntime;
import com.xmlcalabash.io.ReadablePipe;
import com.xmlcalabash.io.WritablePipe;
import com.xmlcalabash.library.DefaultStep;
import com.xmlcalabash.model.RuntimeValue;
import com.xmlcalabash.runtime.XAtomicStep;
import com.xmlcalabash.util.TreeWriter;

public class SynthesizeStep extends DefaultStep implements
        FormatSpecifications, IPipelineLogger {

	private ReadablePipe source = null;
	private WritablePipe result = null;
	private SynthesisWorkerPool mWorkerPool;
	private XProcRuntime mRuntime;

	private static String convertSecondToString(double seconds) {
		long milliseconds = (long) (1000 * seconds);
		int iseconds = (int) (seconds);
		return String.format("%d:%02d:%02d.%d", iseconds / 3600,
		        (iseconds % 3600) / 60, (iseconds % 60), milliseconds - 1000
		                * iseconds);
	}

	public static XdmNode getFirstChild(XdmNode node) {
		XdmSequenceIterator iter = node.axisIterator(Axis.CHILD);
		if (iter.hasNext()) {
			return (XdmNode) iter.next();
		} else {
			return null;
		}
	}

	public SynthesizeStep(XProcRuntime runtime, XAtomicStep step,
	        TTSRegistry ttsRegistry, AudioEncoder encoder) {
		super(runtime, step);
		mRuntime = runtime;
		printInfo("New synthesize step. TTSregistry set: "
		        + (ttsRegistry != null) + ", AudioEncoder set: "
		        + (encoder != null));
		mWorkerPool = new SynthesisWorkerPool(25, ttsRegistry, encoder, this);
	}

	@Override
	synchronized public void printInfo(String message) {
		mRuntime.getMessageListener().info(this, null, message);
	}

	@Override
	synchronized public void printDebug(String message) {
		if (mRuntime.getDebug()) {
			mRuntime.getMessageListener().info(this, null, message);
		}
	}

	public void setInput(String port, ReadablePipe pipe) {
		if ("source".equals(port)) {
			source = pipe;
		}
	}

	public void setOutput(String port, WritablePipe pipe) {
		result = pipe;
	}

	@Override
	public void setOption(QName name, RuntimeValue value) {
		super.setOption(name, value);
	}

	public void reset() {
		source.resetReader();
		result.resetWriter();
	}

	public void traverse(XdmNode node) {
		if (SentenceTag.equals(node.getNodeName())) {
			mWorkerPool.pushSSML(node);
		} else {
			XdmSequenceIterator iter = node.axisIterator(Axis.CHILD);
			while (iter.hasNext()) {
				traverse((XdmNode) iter.next());
			}
		}
	}

	public void run() throws SaxonApiException {
		super.run();

		// dispatch the SSML sentences to the threads
		List<SoundFragment> allSoundFragments = Collections
		        .synchronizedList(new LinkedList<SoundFragment>());
		mWorkerPool.initialize(allSoundFragments);
		while (source.moreDocuments()) {
			traverse(getFirstChild(source.read()));
			mWorkerPool.endSection();
		}

		// run the synthesis/encoding threads
		mWorkerPool.synthesizeAndWait();

		printInfo("number of sound fragments: " + allSoundFragments.size());

		TreeWriter tw = new TreeWriter(runtime);
		tw.startDocument(runtime.getStaticBaseURI());
		tw.addStartElement(OutputRootTag);

		for (SoundFragment sf : allSoundFragments) {
			tw.addStartElement(ClipTag);
			tw.addAttribute(Audio_attr_id, sf.id);
			tw.addAttribute(Audio_attr_clipBegin,
			        convertSecondToString(sf.clipBegin));
			tw.addAttribute(Audio_attr_clipEnd,
			        convertSecondToString(sf.clipEnd));
			tw.addAttribute(Audio_attr_src, sf.soundFileURI);
			tw.addEndElement();
		}

		tw.addEndElement();
		tw.endDocument();

		result.write(tw.getResult());
	}
}
