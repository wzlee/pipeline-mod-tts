package org.daisy.pipeline.tts;

import net.sf.saxon.s9api.QName;

/**
 * Transform the SSML according to the TTS engine's features and bugs
 */
public interface SSMLAdapter {
	String getHeader();

	String getFooter();

	/**
	 * @return null to discard the element
	 */
	QName adaptElement(QName element);

	/**
	 * @return null to discard the attribute
	 */
	QName adaptAttributeName(QName element, QName attr, String value);

	String adaptAttributeValue(QName element, QName attr, String value);
}
