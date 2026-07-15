import React from 'react';

// Standard Code 39 character patterns.
// '1' represents a wide element (bar or space), '0' represents a narrow element.
// Index 0, 2, 4, 6, 8 are BARS. Index 1, 3, 5, 7 are SPACES.
const CODE39_PATTERNS: Record<string, string> = {
  '0': '000110100',
  '1': '100100001',
  '2': '001100001',
  '3': '101100000',
  '4': '000110001',
  '5': '100110000',
  '6': '001100000',
  '7': '000100101',
  '8': '100100100',
  '9': '001100100',
  'A': '100001001',
  'B': '001001001',
  'C': '101001000',
  'D': '000011001',
  'E': '100011000',
  'F': '001011000',
  'G': '000001101',
  'H': '100001100',
  'I': '001001100',
  'J': '000011100',
  'K': '100000011',
  'L': '001000011',
  'M': '101000010',
  'N': '000010011',
  'O': '100010010',
  'P': '001010010',
  'Q': '000000111',
  'R': '100000110',
  'S': '001000110',
  'T': '000010110',
  'U': '110000001',
  'V': '011000001',
  'W': '111000000',
  'X': '010010001',
  'Y': '110010000',
  'Z': '011010000',
  '-': '010000101',
  '.': '110000100',
  ' ': '011000100',
  '*': '010010100',
  '$': '010101000',
  '/': '010100010',
  '+': '010001010',
  '%': '000101010'
};

interface BarcodeProps {
  value: string;
  height?: number;
  narrowWidth?: number;
  wideFactor?: number;
}

export const Barcode: React.FC<BarcodeProps> = ({
  value,
  height = 50,
  narrowWidth = 1.5,
  wideFactor = 2.5
}) => {
  // Convert value to uppercase and wrap with start/stop asterisks.
  // We only include valid characters.
  const cleanValue = value.toUpperCase().trim();
  const characters = `*${cleanValue}*`;
  
  const wideWidth = narrowWidth * wideFactor;
  
  // Calculate SVG elements
  let currentX = 0;
  const paths: React.ReactNode[] = [];

  for (let c = 0; c < characters.length; c++) {
    const char = characters[c];
    const pattern = CODE39_PATTERNS[char] || CODE39_PATTERNS[' '];

    for (let i = 0; i < 9; i++) {
      const isBar = i % 2 === 0;
      const isWide = pattern[i] === '1';
      const w = isWide ? wideWidth : narrowWidth;

      if (isBar) {
        paths.push(
          <rect
            key={`${c}-${i}`}
            x={currentX}
            y={0}
            width={w}
            height={height}
            fill="#0f172a"
          />
        );
      }
      currentX += w;
    }

    // Inter-character gap (always narrow space)
    currentX += narrowWidth;
  }

  // Calculate SVG total width
  const totalWidth = currentX - narrowWidth; // remove last extra gap

  return (
    <svg
      width="100%"
      height="100%"
      viewBox={`0 0 ${totalWidth} ${height}`}
      preserveAspectRatio="none"
      className="max-w-full"
    >
      <g>{paths}</g>
    </svg>
  );
};

export default Barcode;
