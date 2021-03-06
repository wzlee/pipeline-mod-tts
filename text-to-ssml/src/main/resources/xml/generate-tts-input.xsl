<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:ssml="http://www.w3.org/2001/10/synthesis"
    xmlns:tmp="http://www.daisy.org/ns/pipeline/tmp"
    exclude-result-prefixes="#all"
    version="2.0">

  <!--======================================================================= -->
  <!-- Create a SSML file for every future TTS thread. The SSML files will -->
  <!-- contain a list of SSML sentences. Each one carries the CSS -->
  <!-- properties inherited from their parents. The CSS cues and pauses are -->
  <!-- all handled by this script, including the ones inside the -->
  <!-- sentences. Aside from the pauses and the cues, the sentences' -->
  <!-- content is left unchanged. -->
  <!-- For now, cues' location are relative to the CSS sheet location. -->
  <!--======================================================================= -->

  <xsl:param name="css-sheet-uri"/>
  <xsl:variable name="css-sheet-dir" select="substring-before($css-sheet-uri, tokenize($css-sheet-uri, '/')[last()])"/>

  <xsl:variable name="tmp-ns" select="'http://www.daisy.org/ns/pipeline/tmp'"/>

  <!-- ========= bind every cue and pause to its most relevant sentence ========= -->
  <!-- ========= (document order is kept on purpose)                    ========= -->

  <xsl:variable name="bindings">
    <root>
      <xsl:apply-templates mode="build-bindings" select="/*"/>
    </root>
  </xsl:variable>

  <xsl:template match="*" mode="build-before-binding">
    <xsl:param name="sentence-id"/>
    <xsl:if test="@tmp:pause-before or @tmp:cue-before">
      <bind sentence="{$sentence-id}">
	<xsl:copy-of select="@tmp:pause-before"/>
	<xsl:copy-of select="@tmp:cue-before"/>
      </bind>
    </xsl:if>
  </xsl:template>

  <xsl:template match="*" mode="build-after-binding">
    <xsl:param name="sentence-id"/>
    <xsl:if test="@tmp:pause-after or @tmp:cue-after">
      <bind sentence="{$sentence-id}">
	<xsl:copy-of select="@tmp:cue-after"/>
	<xsl:copy-of select="@tmp:pause-after"/>
      </bind>
    </xsl:if>
  </xsl:template>

  <xsl:template match="ssml:s" mode="build-bindings" priority="2">
    <xsl:apply-templates select="." mode="build-before-binding">
      <xsl:with-param name="sentence-id" select="@id"/>
    </xsl:apply-templates>
    <content sentence="{@id}"/>
    <xsl:apply-templates select="." mode="build-after-binding">
      <xsl:with-param name="sentence-id" select="@id"/>
    </xsl:apply-templates>
  </xsl:template>

  <xsl:template match="*" mode="build-bindings-no-sentence">
    <xsl:param name="sentence-id"/>
    <xsl:apply-templates select="." mode="build-before-binding">
      <xsl:with-param name="sentence-id" select="$sentence-id"/>
    </xsl:apply-templates>
    <xsl:apply-templates select="*" mode="build-bindings-no-sentence">
      <xsl:with-param name="sentence-id" select="$sentence-id"/>
    </xsl:apply-templates>
    <xsl:apply-templates select="." mode="build-after-binding">
      <xsl:with-param name="sentence-id" select="$sentence-id"/>
    </xsl:apply-templates>
  </xsl:template>

  <xsl:template match="*" mode="build-bindings" priority="1">
    <xsl:choose>
      <xsl:when test="@tmp:pause-before or @tmp:cue-before or @tmp:pause-after or @tmp:cue-after">
	<xsl:variable name="descendants" select="descendant::ssml:s" />
	<xsl:choose>
	  <xsl:when test="$descendants">
	    <xsl:apply-templates select="." mode="build-before-binding">
	      <xsl:with-param name="sentence-id" select="$descendants[1]/@id"/>
	    </xsl:apply-templates>
	    <xsl:apply-templates select="*" mode="build-bindings"/>
	    <xsl:apply-templates select="." mode="build-after-binding">
	      <xsl:with-param name="sentence-id" select="$descendants[last()]/@id"/>
	    </xsl:apply-templates>
	  </xsl:when>
	  <xsl:otherwise>
	    <!-- This branch contains no sentence. We take a sentence from the nearest sub-tree -->
	    <xsl:variable name="prev-sentence-ancestor" select="ancestor::*[preceding-sibling::*/descendant-or-self::ssml:s[1]][1]" />
	    <xsl:variable name="next-sentence-ancestor" select="ancestor::*[following-sibling::*/descendant-or-self::ssml:s[1]][1]" />
	    <xsl:apply-templates select="." mode="build-bindings-no-sentence">
	      <xsl:with-param name="sentence-id"
			      select="if ($prev-sentence-ancestor/ancestor::*[self = $next-sentence-ancestor]) then
				      ($prev-sentence-ancestor/preceding-sibling::*[descendant-or-self::ssml:s[1]][1]/descendant-or-self::ssml:s[last()]/@id) else
				      ($next-sentence-ancestor/following-sibling::*/descendant-or-self::ssml:s[1]/@id)"/>
	    </xsl:apply-templates>
	  </xsl:otherwise>
	</xsl:choose>
      </xsl:when>
      <xsl:otherwise>
	<xsl:apply-templates select="*" mode="build-bindings"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ========= iterate over the sentences ========= -->

  <xsl:template match="/">
    <tmp:root>
      <xsl:for-each-group select="//ssml:s" group-adjacent="@thread-id">
	<ssml:speak>
	  <xsl:for-each select="current-group()">
	    <ssml:s>
	      <xsl:variable name="sentence" select="current()"/>
	      <xsl:copy-of select="$sentence/@*"/>
	      <xsl:apply-templates select="$sentence" mode="project-css-properties">
		<xsl:with-param name="properties"
				select="'voice-family,richness,volume,rate,stress,speech-rate,pitch,pitch-range,speak,azimuth,speak-punctuation,speak-numeral,elevation'"/>
	      </xsl:apply-templates>
	      <xsl:attribute namespace="http://www.w3.org/XML/1998/namespace" name="lang">
		<xsl:value-of select="$sentence/ancestor-or-self::*[@xml:lang][1]/@xml:lang"/>
	      </xsl:attribute>
	      <xsl:for-each select="$bindings//*[@sentence = $sentence/@id]">
		<xsl:choose>
		  <xsl:when test="current()/@tmp:pause-before or current()/@tmp:cue-before or current()/@tmp:pause-after or current()/@tmp:cue-after">
		    <xsl:apply-templates select="current()/@tmp:pause-before|current()/@tmp:pause-after" mode="pause"/>
		    <xsl:apply-templates select="current()/@tmp:cue-before|current()/@tmp:cue-after" mode="cue"/>
		  </xsl:when>
		  <xsl:otherwise>
		    <!-- sentence content -->
		    <xsl:apply-templates select="$sentence/node()" mode="inside-sentence"/>
		    <ssml:break time="250ms"/>
		  </xsl:otherwise>
		</xsl:choose>
	      </xsl:for-each>
	    </ssml:s>
	  </xsl:for-each>
	</ssml:speak>
      </xsl:for-each-group>
    </tmp:root>
  </xsl:template>

  <!-- === copy the sentences' content and add the cues and pauses if necessary === -->
  <xsl:template match="*" mode="inside-sentence">
    <xsl:apply-templates select="@tmp:pause-before" mode="pause"/>
    <xsl:apply-templates select="@tmp:cue-before" mode="cue"/>

    <xsl:element name="{name()}" namespace="{namespace-uri()}">
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates select="node()" mode="inside-sentence"/>
    </xsl:element>

    <xsl:apply-templates select="@tmp:cue-after" mode="cue"/>
    <xsl:apply-templates select="@tmp:pause-after" mode="pause"/>
  </xsl:template>

  <xsl:template match="text()" mode="inside-sentence">
    <xsl:value-of select="."/>
  </xsl:template>

  <xsl:template match="@*" mode="pause">
    <ssml:break time="{.}"/>
  </xsl:template>

  <xsl:template match="@*" mode="cue">
    <xsl:variable name="abs-uri" select="resolve-uri(., $css-sheet-dir)"/>
    <xsl:if test="starts-with($abs-uri, 'file:/')">
      <xsl:choose>
    	<xsl:when test="starts-with($abs-uri, 'file:///')">
    	  <ssml:audio src="{substring-after($abs-uri, 'file://')}"/>
    	</xsl:when>
    	<xsl:otherwise>
    	  <ssml:audio src="{substring-after($abs-uri, 'file:')}"/>
    	</xsl:otherwise>
      </xsl:choose>
    </xsl:if>
  </xsl:template>

  <xsl:template match="*" mode="project-css-properties">
    <xsl:param name="properties"/>
    <xsl:if test="$properties != ''">
      <xsl:variable name="property" select="substring-before($properties, ',')"/>
      <xsl:variable name="ref"
		    select="ancestor-or-self::*[@*[local-name() = $property and namespace-uri() = $tmp-ns]][1]"/>
      <xsl:if test="$ref">
	<xsl:attribute namespace="{$tmp-ns}" name="{$property}">
	  <xsl:value-of select="$ref/@*[local-name() = $property and namespace-uri() = $tmp-ns]" />
	</xsl:attribute>
      </xsl:if>
      <xsl:apply-templates select="." mode="project-css-properties">
	<xsl:with-param name="properties" select="substring-after($properties, ',')"/>
      </xsl:apply-templates>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>

