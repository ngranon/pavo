/*

PDFParser - project pavo(http://code.google.com/p/pavo/)

Licensed under the MIT License

Copyright (c) 2009 genephics design, Inc.(http://www.genephics.co.jp/)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

以下に定める条件に従い、本ソフトウェアおよび関連文書のファイル（以下「ソフトウェ
ア」）の複製を取得するすべての人に対し、ソフトウェアを無制限に扱うことを無償で
許可します。これには、ソフトウェアの複製を使用、複写、変更、結合、掲載、頒布、
サブライセンス、および/または販売する権利、およびソフトウェアを提供する相手に
同じことを許可する権利も無制限に含まれます。

上記の著作権表示および本許諾表示を、ソフトウェアのすべての複製または重要な部分に
記載するものとします。

ソフトウェアは「現状のまま」で、明示であるか暗黙であるかを問わず、何らの保証も
なく提供されます。ここでいう保証とは、商品性、特定の目的への適合性、および権利非
侵害についての保証も含みますが、それに限定されるものではありません。
作者または著作権者は、契約行為、不法行為、またはそれ以外であろうと、ソフトウェア
に起因または関連し、あるいはソフトウェアの使用またはその他の扱いによって生じる
一切の請求、損害、その他の義務について何らの責任も負わないものとします。 

*/

package jp.co.genephics.pavo.pdf.extractor.threads
{
	import __AS3__.vec.Vector;
	
	import jp.co.genephics.pavo.pdf.extractor.models.PDFOutlineEntity;
	import jp.co.genephics.pavo.pdf.parser.cmap.CMapConverter;
	import jp.co.genephics.pavo.pdf.parser.constants.Status;
	import jp.co.genephics.pavo.pdf.parser.models.Page;
	import jp.co.genephics.pavo.pdf.parser.threads.ThreadBase;
	import jp.co.genephics.pavo.pdf.parser.utils.LigatureUtil;
	import jp.co.genephics.utils.StringUtil;
	
	/**
	 * Contents情報からテキスト部分を抜き出すThreadクラス
	 * 
	 * @author genephics design, Inc.
	 */
	public class ContentsTextBuilderThread extends ThreadBase
	{

		// ----------------------------------------------------
		// private props
		// ----------------------------------------------------

		private static const LUMP_COUNT:int = 32;
		private var _sectionArray:Vector.<PDFOutlineEntity>;
		private var _section:PDFOutlineEntity;
		private var _page:Page;
		private var _yIndex:int = int.MAX_VALUE;
		private var _outlinesNum:int;
		private var _currentOutline:int = -1;
		private var _pageCounter:int;
		private var _converter:CMapConverter = CMapConverter.instance;
		private var _textCounter:int = 0;
		private var _regExpForCmap:RegExp = /(?!5c)28(.*?)(?<!5c)29/g;
		
		/**
		 * コンストラクタ
		 */
		public function ContentsTextBuilderThread(sectionArray:Vector.<PDFOutlineEntity>, page:Page, pageCounter:int)
		{
			super();
			__status = Status.STATUS_CONVERT_CHARCODE;
			
			_sectionArray = sectionArray;
			_page = page;
			_outlinesNum = page.outlines.length;
			_pageCounter = pageCounter;
		}
		
		/**
		 * スレッド実行関数。そのページのコンテンツ情報に含まれるストリーム内の文字列を順番に処理します。
		 */
		override protected function run():void
		{
			error(Error, __errorHandler);
			
			var maxLen:int = _page.contentsTextArray.length;

			// LUMP_COUNTコンテンツづつ処理を行う
			for (var i:int = 0; i < LUMP_COUNT; i++)
			{
				var contentsText:Array = _page.contentsTextArray[_textCounter];
				if (contentsText)
				{
					_convertContents(contentsText, _sectionArray);
				}
				_textCounter++;
				if (_textCounter >= maxLen) return;
			}
			__next(run);
		}
		
		/**
		 * @private
		 */
		private function _convertContents(contentsText:Array, sectionArray:Vector.<PDFOutlineEntity>):void
		{
			// 現在のセッション取得
			var section:PDFOutlineEntity = sectionArray[sectionArray.length - 1];

			var key:String = contentsText[0];
			var value:String = contentsText[1];
			var binaryValue:String = contentsText[2];
			var _regExp:RegExp = /\((.+?)\)|\<(.+?)\>/g;
		
			if (key == "TJ" || key == "Tj")
			{
				var result:Array = _regExp.exec(value);
				
				while (result)
				{
					if (result[1] != undefined)
					{
						if (_converter.isDefaultCmap())
						{
							section.body += result[1];
						}
						else
						{
							// CMapデータ抽出用
							var resultForCmap:Array = _regExpForCmap.exec(binaryValue);
							
							while(resultForCmap)
							{
								var tmp:String = _getString(resultForCmap[1],2);
								section.body += tmp;
								resultForCmap = _regExpForCmap.exec(binaryValue);
							}
							// CMapが埋め込まれている場合、1度で処理が終わるので、ループから抜ける
							break;
						}
					}
					if (result.length > 2 && result[2] != undefined)
					{
						var tmp2:String = _getString(result[2]);
						section.body = section.body.concat(tmp2);
					}
					
					result = _regExp.exec(value);
				}
			}
			else if (key == "Tm")
			{
				section.body += " ";
				
				var tmArray:Array = value.split(" ");
				_yIndex = tmArray[5]; // y座標
				
				if (_currentOutline+1 < _outlinesNum && _yIndex <= _page.outlines[_currentOutline+1]["destElement"]["top"])
				{
					_currentOutline++;
					section = new PDFOutlineEntity();
					section.page = _pageCounter+1;
					section.name = _page.outlines[_currentOutline]["title"];
					section.body = "";
					sectionArray.push(section);
				}
			}
			else if (key == "Tf" || key == "TF")
			{
				value = StringUtil.trim(value);
				var tfArray:Array = value.split(" ");
				
				var font:* = _page.resource.fonts[tfArray[0]];
				
				if (font && font.hasOwnProperty("toUnicodeMap") && font["toUnicodeMap"] != null)
				{
					_converter.changeCmap(font["toUnicodeMap"]);
				}
				else
				{
					_converter.changeCmap();
				}
			}
		}
		
		/**
		 * @private
		 */
		private function _getString(target:String, length:int=4):String
		{
			var retVal:Array = [];
			var len:int = target.length;
			var tmp:String = "";
			var cod:String = "";
			
			for (var i:int = 0; i < len; i += length)
			{
				tmp = target.substr(i,length);
				cod = _getUnicodeString(tmp);
				
				if (cod && cod.length > 0)
				{
					var ligature:String = LigatureUtil.getUnicodeString(cod);
					if (ligature)
					{
						retVal.push(ligature);
					}
					else
					{
						retVal.push(String.fromCharCode("0x"+cod));
					}
				}
			}
			
			return retVal.join("");
		}

		/**
		 * @private
		 */
		private function _getUnicodeString(cid:String):String
		{
			return _converter.covertToUnicode(cid);
		}
	}
}