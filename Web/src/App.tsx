import { HashRouter, Route, Routes } from 'react-router-dom';
import Home from './pages/Home';
import Android from './pages/Android';
import Windows from './pages/Windows';
import Macos from './pages/Macos';
import Linux from './pages/Linux';
import Faq from './pages/Faq';

export default function App() {
  return (
    <HashRouter>
      <div className="min-h-screen bg-[#07070a]">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/android" element={<Android />} />
          <Route path="/windows" element={<Windows />} />
          <Route path="/macos" element={<Macos />} />
          <Route path="/linux" element={<Linux />} />
          <Route path="/faq" element={<Faq />} />
          <Route path="*" element={<Home />} />
        </Routes>
      </div>
    </HashRouter>
  );
}
